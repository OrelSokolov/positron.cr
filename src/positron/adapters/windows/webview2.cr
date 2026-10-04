require "json"
require "log"
require "uri"
require "./lib_webview"

module Positron
  module Adapters
    module Windows
      # Windows WebView adapter backed by the vendored `webview.dll`
      # (WebView2 / Microsoft Edge — see lib_webview.cr).
      #
      # Implements the platform-agnostic WebViewPort contract:
      #   - Creates a Win32 window hosting the WebView2 control.
      #   - Loads URLs or raw HTML; injects the `PositronBridge.postMessage` shim.
      #   - Forwards JS messages to the host and evaluates host responses.
      #   - Window management through Win32 calls on the native HWND.
      #
      # The webview C API drives everything through `webview_dispatch` so all
      # WebView2 calls happen on the UI thread inside the message pump.
      class WebView2 < WebViewPort
        @wv : LibWebview::WebviewT
        @hwnd : Void*
        @callback : Proc(String, String)?
        @close_to_tray : Bool = true
        @last_size : {Int32, Int32} = {-1, -1}
        @last_position : {Int32, Int32} = {-1, -1}
        @last_maximized : Bool = false
        @fullscreen_rect : Win32::LibUser32::Rect?
        @fullscreen_style : UInt64?

        # Positron is single-window by design: the subclassed WndProc and the
        # dispatch callbacks reach the adapter through this class variable.
        @@instance : WebView2?
        @@pending_blocks = {} of Void* => Proc(Nil)

        WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
          adapter = @@instance
          return Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam) unless adapter

          case msg
          when Win32::WM_CLOSE
            if adapter.close_to_tray?
              adapter.hide
            else
              adapter.terminate_event_loop
            end
            0_i64
          when Win32::WM_SIZE, Win32::WM_MOVE
            adapter.emit_window_state_changes
            Win32::LibUser32.CallWindowProcW(adapter.original_wndproc, hwnd, msg, wparam, lparam)
          else
            Win32::LibUser32.CallWindowProcW(adapter.original_wndproc, hwnd, msg, wparam, lparam)
          end
        end

        BIND_PROC = ->(id : UInt8*, req : UInt8*, arg : Void*) do
          adapter = @@instance
          return unless adapter

          request = String.new(req)
          json =
            begin
              JSON.parse(request).as_a.first?.try(&.as_s).to_s
            rescue ex
              Log.warn { "webview2: malformed bridge message: #{ex.message}" }
              ""
            end

          response = adapter.callback.try(&.call(json)) || ""
          unless response.empty?
            # We are on the UI thread inside the message pump: evaluate
            # directly, before the promise below resolves.
            LibWebview.eval(adapter.webview_handle, response)
          end
          LibWebview.return_result(adapter.webview_handle, id, 0, "null")
        end

        DISPATCH_PROC = ->(w : LibWebview::WebviewT, arg : Void*) do
          block = @@pending_blocks.delete(arg)
          block.try(&.call)
        end

        def initialize
          @wv = Pointer(Void).null
          @hwnd = Pointer(Void).null
          @original_wndproc = Pointer(Void).null
        end
        def create(config : WebViewConfig)
          LibWebview.load!

          debug = Dev.enabled? ? 1 : 0
          @wv = LibWebview.create(debug)
          if @wv.null?
            raise LibWebview::Error.new(
              "WebView2 initialization failed — is the Microsoft Edge WebView2 " \
              "runtime installed? (https://developer.microsoft.com/microsoft-edge/webview2/)")
          end

          @hwnd = LibWebview.get_native_handle(@wv, LibWebview::HANDLE_KIND_UI_WINDOW)
          @close_to_tray = config.close_to_tray
          @@instance = self

          LibWebview.set_title(@wv, config.title)
          hints = config.resizable ? LibWebview::HINT_NONE : LibWebview::HINT_FIXED
          LibWebview.set_size(@wv, config.width, config.height, hints)

          subclass_window
          if icon = config.icon
            apply_window_icon(icon)
          end
        end

        def load_url(url : String)
          LibWebview.navigate(@wv, url)
        end

        def load_html(html : String, base_url : String? = nil)
          # base_url is meaningless for NavigateToString (data-island).
          LibWebview.set_html(@wv, html)
        end

        # All WebView2 calls must happen on the UI thread; webview_dispatch
        # marshals the call into the message pump. Called before the pump
        # runs (during on_ready) the block is simply queued.
        def eval_js(script : String)
          dispatch_on_ui { LibWebview.eval(@wv, script) }
        end

        def show
          Win32::LibUser32.ShowWindow(@hwnd, Win32::SW_SHOW)
        end

        def hide
          Win32::LibUser32.ShowWindow(@hwnd, Win32::SW_HIDE)
        end

        def close
          terminate_event_loop
        end

        def bind(name : String, &block : String -> String)
          @callback = block

          code = LibWebview.bind(@wv, name, BIND_PROC.pointer, Box.box(self))
          if code < 0
            raise "Failed to register JS binding '#{name}' (webview error #{code})"
          end

          # The binding glue (window.<name>) is injected by webview_bind; our
          # shim is registered right after and references the binding lazily.
          shim = <<-JS
            window.PositronBridge = window.PositronBridge || {
              postMessage: function(jsonString) {
                window.#{name}(jsonString);
              }
            };
          JS
          LibWebview.init(@wv, shim)
        end

        # Schedule a block on the UI thread (used by the event loop's
        # run_on_main and by eval_js).
        def dispatch_on_ui(&block : ->) : Nil
          box = Box.box(block)
          @@pending_blocks[box] = block # keep the closure alive until it runs
          LibWebview.dispatch(@wv, DISPATCH_PROC.pointer, box)
        end

        protected def terminate_event_loop : Nil
          LibWebview.terminate(@wv)
        end

        protected def run_event_loop : Nil
          LibWebview.run(@wv)
        end

        protected def webview_handle : LibWebview::WebviewT
          @wv
        end

        protected def original_wndproc : Void*
          @original_wndproc
        end

        protected def close_to_tray? : Bool
          @close_to_tray
        end

        protected def callback : Proc(String, String)?
          @callback
        end

        # Serve a custom URI scheme from the host process: not supported by
        # the webview C API. Positron's embedded assets are inlined into the
        # HTML, so examples are unaffected; a future implementation could
        # use WebView2's SetVirtualHostNameToFolderMapping.
        def register_uri_scheme(scheme : String, &handler : String -> SchemeResponse?)
          raise "register_uri_scheme is not supported by the Windows webview adapter"
        end

        # --- Window management (WebViewPort) ---

        def set_title(title : String) : Nil
          LibWebview.set_title(@wv, title)
        end

        def resize(width : Int32, height : Int32) : Nil
          LibWebview.set_size(@wv, width, height, LibWebview::HINT_NONE)
        end

        def center : Nil
          monitor = Win32::LibUser32.MonitorFromWindow(@hwnd, Win32::MONITOR_DEFAULTTONEAREST)
          info = Win32::LibUser32::MonitorInfo.new
          info.cb_size = sizeof(Win32::LibUser32::MonitorInfo)
          return unless Win32::LibUser32.GetMonitorInfoW(monitor, pointerof(info)) != 0

          wr = Win32::LibUser32::Rect.new
          Win32::LibUser32.GetWindowRect(@hwnd, pointerof(wr))
          width = wr.right - wr.left
          height = wr.bottom - wr.top
          x = info.rc_work.left + (info.rc_work.right - info.rc_work.left - width) // 2
          y = info.rc_work.top + (info.rc_work.bottom - info.rc_work.top - height) // 2
          Win32::LibUser32.SetWindowPos(@hwnd, Pointer(Void).null, x, y, 0, 0,
            Win32::SWP_NOSIZE | Win32::SWP_NOZORDER)
        end

        def set_minimum_size(width : Int32, height : Int32) : Nil
          LibWebview.set_size(@wv, width, height, LibWebview::HINT_MIN)
        end

        def set_maximum_size(width : Int32, height : Int32) : Nil
          LibWebview.set_size(@wv, width, height, LibWebview::HINT_MAX)
        end

        def maximize : Nil
          Win32::LibUser32.ShowWindow(@hwnd, Win32::SW_MAXIMIZE)
        end

        def unmaximize : Nil
          Win32::LibUser32.ShowWindow(@hwnd, Win32::SW_RESTORE)
        end

        def maximized? : Bool
          Win32::LibUser32.IsZoomed(@hwnd) != 0
        end

        def fullscreen : Nil
          return if @fullscreen_style
          style = Win32::LibUser32.GetWindowLongPtrW(@hwnd, Win32::GWL_STYLE)

          wr = Win32::LibUser32::Rect.new
          Win32::LibUser32.GetWindowRect(@hwnd, pointerof(wr))

          monitor = Win32::LibUser32.MonitorFromWindow(@hwnd, Win32::MONITOR_DEFAULTTONEAREST)
          info = Win32::LibUser32::MonitorInfo.new
          info.cb_size = sizeof(Win32::LibUser32::MonitorInfo)
          return unless Win32::LibUser32.GetMonitorInfoW(monitor, pointerof(info)) != 0

          @fullscreen_style = style.to_u64!
          @fullscreen_rect = wr

          Win32::LibUser32.SetWindowLongPtrW(
            @hwnd, Win32::GWL_STYLE,
            (style & ~(Win32::WS_CAPTION | Win32::WS_THICKFRAME).to_i64!).to_i64!)
          Win32::LibUser32.SetWindowPos(@hwnd, Pointer(Void).null,
            info.rc_monitor.left, info.rc_monitor.top,
            info.rc_monitor.right - info.rc_monitor.left,
            info.rc_monitor.bottom - info.rc_monitor.top,
            Win32::SWP_NOZORDER | Win32::SWP_FRAMECHANGED)
          Positron::EventBus.emit("window.fullscreened", JSON.parse(%({})))
        end

        def unfullscreen : Nil
          return unless style = @fullscreen_style
          wr = @fullscreen_rect.not_nil!

          Win32::LibUser32.SetWindowLongPtrW(@hwnd, Win32::GWL_STYLE, style.to_i64!)
          Win32::LibUser32.SetWindowPos(@hwnd, Pointer(Void).null,
            wr.left, wr.top, wr.right - wr.left, wr.bottom - wr.top,
            Win32::SWP_NOZORDER | Win32::SWP_FRAMECHANGED)
          @fullscreen_style = nil
          @fullscreen_rect = nil
          Positron::EventBus.emit("window.unfullscreened", JSON.parse(%({})))
        end

        def set_always_on_top(enabled : Bool) : Nil
          Win32::LibUser32.SetWindowPos(
            @hwnd,
            enabled ? Win32::HWND_TOPMOST : Win32::HWND_NOTOPMOST,
            0, 0, 0, 0,
            Win32::SWP_NOMOVE | Win32::SWP_NOSIZE)
        end

        def set_decorated(decorated : Bool) : Nil
          style = Win32::LibUser32.GetWindowLongPtrW(@hwnd, Win32::GWL_STYLE)
          frame = (Win32::WS_CAPTION | Win32::WS_THICKFRAME).to_i64!
          style = decorated ? style | frame : style & ~frame
          Win32::LibUser32.SetWindowLongPtrW(@hwnd, Win32::GWL_STYLE, style)
          Win32::LibUser32.SetWindowPos(@hwnd, Pointer(Void).null, 0, 0, 0, 0,
            Win32::SWP_NOMOVE | Win32::SWP_NOSIZE | Win32::SWP_NOZORDER | Win32::SWP_FRAMECHANGED)
        end

        def focus : Nil
          Win32::LibUser32.SetForegroundWindow(@hwnd)
        end

        def size : {Int32, Int32}
          cr = Win32::LibUser32::Rect.new
          Win32::LibUser32.GetClientRect(@hwnd, pointerof(cr))
          {cr.right - cr.left, cr.bottom - cr.top}
        end

        def position : {Int32, Int32}
          wr = Win32::LibUser32::Rect.new
          Win32::LibUser32.GetWindowRect(@hwnd, pointerof(wr))
          {wr.left, wr.top}
        end

        # --- Developer tools ---

        def open_devtools : Nil
          # WebView2 devtools are available via F12 / context menu when the
          # webview is created in debug mode (POSITRON_DEV=1).
          raise "open_devtools is not implemented on Windows (run with POSITRON_DEV=1 and press F12)"
        end

        def close_devtools : Nil
          raise "close_devtools is not implemented on Windows"
        end

        protected def emit_window_state_changes
          width, height = size
          if @last_size != {width, height}
            @last_size = {width, height}
            Positron::EventBus.emit(
              "window.resized",
              JSON.parse(%({"width":#{width},"height":#{height}}))
            )
          end

          x, y = position
          if @last_position != {x, y}
            @last_position = {x, y}
            Positron::EventBus.emit(
              "window.moved",
              JSON.parse(%({"x":#{x},"y":#{y}}))
            )
          end

          maximized = maximized?
          if @last_maximized != maximized
            @last_maximized = maximized
            Positron::EventBus.emit(
              maximized ? "window.maximized" : "window.unmaximized",
              JSON.parse(%({}))
            )
          end
        end

        private def subclass_window : Nil
          @original_wndproc = Pointer(Void).new(Win32::LibUser32.SetWindowLongPtrW(
            @hwnd, Win32::GWLP_WNDPROC, WNDPROC.pointer.address.to_i64!).to_u64!)
        end

        private def apply_window_icon(icon : IconSource) : Nil
          hicon = load_hicon(icon)
          return if hicon.null?
          Win32::LibUser32.SendMessageW(@hwnd, Win32::WM_SETICON, Win32::ICON_BIG.to_u64!, hicon.address)
          Win32::LibUser32.SendMessageW(@hwnd, Win32::WM_SETICON, Win32::ICON_SMALL.to_u64!, hicon.address)
        end

        # ICO from a temp file via LoadImageW; PNG via GDI+; SVG is not
        # decodable natively — keep the default window icon.
        private def load_hicon(icon : IconSource) : Void*
          ext = case icon.format
                when :ico then "ico"
                when :png then "png"
                else           return Pointer(Void).null
                end

          path = File.join(Dir.tempdir, "positron_icon_#{Process.pid}_#{Time.utc.to_unix_ms}.#{ext}")
          File.write(path, icon.bytes)
          hicon =
            if icon.format == :ico
              Win32::LibUser32.LoadImageW(Pointer(Void).null,
                Win32.wstr(path).to_unsafe, Win32::IMAGE_ICON, 0, 0,
                Win32::LR_LOADFROMFILE | Win32::LR_DEFAULTSIZE)
            else
              Win32.hicon_from_png(path)
            end
          File.delete(path) rescue nil
          hicon
        rescue ex
          Log.warn { "Failed to load window icon: #{ex.message}" }
          Pointer(Void).null
        end
      end
    end
  end
end
