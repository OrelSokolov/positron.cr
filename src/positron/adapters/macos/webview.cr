require "json"
require "log"
require "./objc"

module Positron
  module Adapters
    module MacOS
      # macOS desktop WebView backed by WKWebView inside an NSWindow.
      #
      # Implements the platform-agnostic WebViewPort contract:
      #   - Creates an NSWindow + WKWebView (single-window by design).
      #   - Loads URLs or raw HTML.
      #   - Injects a generic `PositronBridge.postMessage` shim as a
      #     WKUserScript and receives messages through a dynamically
      #     registered WKScriptMessageHandler implementation.
      #   - Serves custom URI schemes via a dynamically registered
      #     WKURLSchemeHandler implementation (embedded assets need no
      #     HTTP server). Handlers must be registered before `create`.
      #   - Full M3 window management API on NSWindow.
      #
      # Struct/float/4+-argument calls go through `ObjC::Call`
      # (NSInvocation) — see `adapters/macos/objc.cr`.
      class WKWebView < WebViewPort
        # NSWindowStyleMask: titled|closable|miniaturizable|resizable
        STYLED_MASK      = 1_u64 | 2_u64 | 4_u64 | 8_u64
        UNSTYLED_MASK    = 7_u64
        BACKING_BUFFERED = 2_i64
        FLOATING_LEVEL   = 3_i64 # kCGFloatingWindowLevel

        @ns_window : Void*?
        @wk_view : Void*?
        @user_controller : Void*?
        @delegate_obj : Void*?
        @message_handler_obj : Void*?
        @scheme_handler_obj : Void*?
        @callback : Proc(String, String)?
        @close_to_tray : Bool = true
        @style_mask : UInt64 = STYLED_MASK
        @last_size : {Int32, Int32} = {-1, -1}
        @last_position : {Int32, Int32} = {-1, -1}
        @last_maximized : Bool = false
        @scheme_handlers = {} of String => Proc(String, Positron::SchemeResponse?)

        # IMP proc objects — kept alive so the C function pointers stay
        # valid for the lifetime of the process.
        @@message_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
        @@scheme_start_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
        @@scheme_stop_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
        @@should_close_imp : Proc(Void*, Void*, Void*, Bool)?
        @@did_resize_imp : Proc(Void*, Void*, Void*, Nil)?
        @@did_move_imp : Proc(Void*, Void*, Void*, Nil)?
        @@did_zoom_imp : Proc(Void*, Void*, Void*, Nil)?

        def initialize
        end

        def create(config : WebViewConfig)
          App.ensure_app

          ObjC.with_autorelease_pool do
            wk_config = ObjC.send0(ObjC.cls("WKWebViewConfiguration"), ObjC.sel("new"))
            @user_controller = ObjC.send0(wk_config, ObjC.sel("userContentController"))

            # Custom URI schemes must be attached to the configuration
            # before the WKWebView is instantiated (see #register_uri_scheme).
            unless @scheme_handlers.empty?
              @scheme_handler_obj = build_scheme_handler
              @scheme_handlers.each_key do |scheme|
                ObjC.send2(
                  wk_config,
                  ObjC.sel("setURLSchemeHandler:forURLScheme:"),
                  @scheme_handler_obj.not_nil!, ObjC.nsstr(scheme))
              end
            end

            # Right-click "Inspect Element"; used by open_devtools.
            prefs = ObjC.send0(wk_config, ObjC.sel("preferences"))
            ObjC.send2(
              prefs, ObjC.sel("setValue:forKey:"),
              ObjC.nsbool(true), ObjC.nsstr("developerExtrasEnabled"))

            rect = LibObjC::NSRect.new(
              origin: LibObjC::NSPoint.new(x: 0.0, y: 0.0),
              size: LibObjC::NSSize.new(width: config.width.to_f64, height: config.height.to_f64))

            @style_mask = config.resizable ? STYLED_MASK : UNSTYLED_MASK
            window = ObjC.send0(ObjC.cls("NSWindow"), ObjC.sel("alloc"))
            ObjC.invoke_rect3(
              window, "initWithContentRect:styleMask:backing:defer:", rect,
              ObjC.int_arg(@style_mask.to_i64),
              ObjC.int_arg(BACKING_BUFFERED),
              ObjC.bool_arg(false))
            ObjC.send1(window, ObjC.sel("setTitle:"), ObjC.nsstr(config.title)) unless config.title.empty?
            if icon = config.icon
              set_app_icon(icon)
            end

            @delegate_obj = build_window_delegate
            ObjC.send1(window, ObjC.sel("setDelegate:"), @delegate_obj.not_nil!)

            @wk_view = ObjC.send0(ObjC.cls("WKWebView"), ObjC.sel("alloc"))
            ObjC.invoke_rect3(
              @wk_view.not_nil!, "initWithFrame:configuration:", rect, wk_config)
            ObjC.send1(window, ObjC.sel("setContentView:"), @wk_view.not_nil!)

            @close_to_tray = config.close_to_tray
            @ns_window = window
          end
        end

        def load_url(url : String)
          request = ObjC.send1(
            ObjC.send0(ObjC.cls("NSURLRequest"), ObjC.sel("alloc")),
            ObjC.sel("initWithURL:"), ObjC.nsurl(url))
          ObjC.send1(wk_view, ObjC.sel("loadRequest:"), request)
        end

        def load_html(html : String, base_url : String? = nil)
          base = base_url ? ObjC.nsurl(base_url) : Pointer(Void).null
          ObjC.send2(wk_view, ObjC.sel("loadHTMLString:baseURL:"), ObjC.nsstr(html), base)
        end

        def eval_js(script : String)
          # A NULL completion handler is explicitly allowed.
          ObjC.send2(
            wk_view, ObjC.sel("evaluateJavaScript:completionHandler:"),
            ObjC.nsstr(script), Pointer(Void).null)
        end

        def show
          ObjC.send1(ns_window, ObjC.sel("makeKeyAndOrderFront:"), Pointer(Void).null)
          App.activate!
        end

        def hide
          ObjC.send1(ns_window, ObjC.sel("orderOut:"), Pointer(Void).null)
        end

        def close
          App.request_stop
        end

        def run_event_loop
          ObjC.send0(App.nsapp, ObjC.sel("run"))
        end

        def bind(name : String, &block : String -> String)
          @callback = block

          @message_handler_obj ||= build_message_handler
          ObjC.send2(
            @user_controller.not_nil!,
            ObjC.sel("addScriptMessageHandler:name:"),
            @message_handler_obj.not_nil!, ObjC.nsstr(name))

          inject_bridge_shim(name)
        end

        def register_uri_scheme(scheme : String, &handler : String -> Positron::SchemeResponse?)
          @scheme_handlers[scheme] = handler
        end

        # --- Window management (WebViewPort) ---

        def set_title(title : String) : Nil
          ObjC.send1(ns_window, ObjC.sel("setTitle:"), ObjC.nsstr(title))
        end

        def resize(width : Int32, height : Int32) : Nil
          set_content_size(width, height)
        end

        def center : Nil
          ObjC.send0(ns_window, ObjC.sel("center"))
        end

        def set_minimum_size(width : Int32, height : Int32) : Nil
          # macOS 26 NSWindow has no minContentSize/maxContentSize — the
          # classic contentMinSize/contentMaxSize selectors are used.
          invoke_size("setContentMinSize:", width, height)
        end

        def set_maximum_size(width : Int32, height : Int32) : Nil
          invoke_size("setContentMaxSize:", width, height)
        end

        def maximize : Nil
          ObjC.send1(ns_window, ObjC.sel("zoom:"), Pointer(Void).null) unless maximized?
        end

        def unmaximize : Nil
          ObjC.send1(ns_window, ObjC.sel("zoom:"), Pointer(Void).null) if maximized?
        end

        def maximized? : Bool
          ObjC.send0_b(ns_window, ObjC.sel("isZoomed"))
        end

        def fullscreen : Nil
          unless ObjC.send0_b(ns_window, ObjC.sel("isFullScreen"))
            ObjC.send1(ns_window, ObjC.sel("toggleFullScreen:"), Pointer(Void).null)
          end
          Positron::EventBus.emit("window.fullscreened", JSON.parse(%({})))
        end

        def unfullscreen : Nil
          if ObjC.send0_b(ns_window, ObjC.sel("isFullScreen"))
            ObjC.send1(ns_window, ObjC.sel("toggleFullScreen:"), Pointer(Void).null)
          end
          Positron::EventBus.emit("window.unfullscreened", JSON.parse(%({})))
        end

        def set_always_on_top(enabled : Bool) : Nil
          ObjC.send1(ns_window, ObjC.sel("setLevel:"), ObjC.int_arg(enabled ? FLOATING_LEVEL : 0))
        end

        def set_decorated(decorated : Bool) : Nil
          ObjC.send1(ns_window, ObjC.sel("setStyleMask:"), ObjC.int_arg(decorated ? @style_mask : 0))
        end

        def focus : Nil
          show
        end

        def size : {Int32, Int32}
          rect = frame
          {rect.size.width.round.to_i32, rect.size.height.round.to_i32}
        end

        # macOS window coordinates are bottom-left origin; the port
        # contract is top-left origin (matches GTK/Windows), so convert.
        def position : {Int32, Int32}
          rect = frame
          y = rect.origin.y.round.to_i32
          screen = ObjC.send0(ObjC.cls("NSScreen"), ObjC.sel("mainScreen"))
          unless screen.null?
            screen_h = ObjC::Call.new(screen, "frame").invoke.ret_rect.size.height
            y = (screen_h - rect.origin.y - rect.size.height).round.to_i32
          end
          {rect.origin.x.round.to_i32, y}
        end

        # --- Developer tools (WebKit private inspector API) ---
        # WKWebView has no public inspector API; developerExtrasEnabled
        # (set in #create) gives right-click "Inspect Element", and the
        # private selectors below (stable for years) open/close it.

        def open_devtools : Nil
          if ObjC.send1_b(wk_view, ObjC.sel("respondsToSelector:"), ObjC.sel("_inspectElement"))
            ObjC.send1(wk_view, ObjC.sel("_inspectElement"), Pointer(Void).null)
          else
            Log.warn { "WKWebView does not support _inspectElement; use right-click → Inspect Element" }
          end
        end

        def close_devtools : Nil
          if ObjC.send1_b(wk_view, ObjC.sel("respondsToSelector:"), ObjC.sel("_closeAllInspectorPresentations"))
            ObjC.send1(wk_view, ObjC.sel("_closeAllInspectorPresentations"), Pointer(Void).null)
          else
            Log.warn { "WKWebView does not support closing the inspector programmatically" }
          end
        end

        # --- Internals ---

        protected def callback : Proc(String, String)?
          @callback
        end

        protected def close_to_tray? : Bool
          @close_to_tray
        end

        private def wk_view : Void*
          @wk_view.not_nil!
        end

        private def ns_window : Void*
          @ns_window.not_nil!
        end

        private def frame : LibObjC::NSRect
          ObjC::Call.new(ns_window, "frame").invoke.ret_rect
        end

        private def set_content_size(width : Int32, height : Int32) : Nil
          invoke_size("setContentSize:", width, height)
        end

        private def invoke_size(selector : String, width : Int32, height : Int32) : Nil
          size = LibObjC::NSSize.new(width: width.to_f64, height: height.to_f64)
          ObjC.send_size(ns_window, selector, size)
        end

        # The app icon has no per-window API on macOS; set it on the
        # dock application icon instead (best available equivalent).
        private def set_app_icon(icon : IconSource) : Nil
          image = nsimage_from(icon)
          ObjC.send1(App.nsapp, ObjC.sel("setApplicationIconImage:"), image) unless image.null?
        end

        private def nsimage_from(icon : IconSource) : Void*
          if icon.ico?
            Log.warn { "ICO icons are not supported by the macOS adapters; ignoring" }
            return Pointer(Void).null
          end
          # NSImage understands PNG (all versions) and SVG data (macOS 11+).
          image = ObjC.send1(
            ObjC.send0(ObjC.cls("NSImage"), ObjC.sel("alloc")),
            ObjC.sel("initWithData:"), ObjC.nsdata(icon.bytes))
          if image.null?
            Log.warn { "macOS: NSImage could not decode the icon data" }
          end
          image
        end

        private def inject_bridge_shim(handler_name : String)
          shim = <<-JS
            window.PositronBridge = window.PositronBridge || {
              postMessage: function(jsonString) {
                window.webkit.messageHandlers.#{handler_name}.postMessage(jsonString);
              }
            };
          JS

          script = ObjC.send3(
            ObjC.send0(ObjC.cls("WKUserScript"), ObjC.sel("alloc")),
            ObjC.sel("initWithSource:injectionTime:forMainFrameOnly:"),
            ObjC.nsstr(shim),
            ObjC.int_arg(0), # WKUserScriptInjectionTimeAtDocumentStart
            ObjC.bool_arg(false)          )
          ObjC.send1(@user_controller.not_nil!, ObjC.sel("addUserScript:"), script)
        end

        # --- ObjC handler objects ---

        # Builds an NSObject subclass implementing
        # `userContentController:didReceiveScriptMessage:` and points it
        # back at this adapter via the ObjC target registry.
        private def build_message_handler : Void*
          objc_class = ObjC.new_class("PositronScriptMessageHandler")
          ObjC.add_protocol(objc_class, "WKScriptMessageHandler")

          @@message_imp = ->(objc_self : Void*, _cmd : Void*, controller : Void*, message : Void*) {
            if adapter = ObjC.target_for(objc_self).as?(WKWebView)
              body = ObjC.send0(message, ObjC.sel("body"))
              if (json = ObjC.to_s(body)) && (cb = adapter.callback)
                response = cb.call(json)
                adapter.eval_js(response) unless response.empty?
              end
            end
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("userContentController:didReceiveScriptMessage:"),
            @@message_imp.not_nil!.pointer.as(Void*), "v@:@@")

          handler = ObjC.send0(objc_class, ObjC.sel("new"))
          ObjC.bind_target(handler, self)
          handler
        end

        # Builds an NSObject subclass implementing WKURLSchemeHandler:
        # requests are served from the registered Crystal handlers and
        # answered with NSHTTPURLResponse + NSData.
        private def build_scheme_handler : Void*
          objc_class = ObjC.new_class("PositronURLSchemeHandler")
          ObjC.add_protocol(objc_class, "WKURLSchemeHandler")

          @@scheme_start_imp = ->(objc_self : Void*, _cmd : Void*, web_view : Void*, task : Void*) {
            adapter = ObjC.target_for(objc_self).as?(WKWebView)
            adapter.handle_scheme_task(task) if adapter
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("webView:startURLSchemeTask:"),
            @@scheme_start_imp.not_nil!.pointer.as(Void*), "v@:@@")

          @@scheme_stop_imp = ->(objc_self : Void*, _cmd : Void*, web_view : Void*, task : Void*) {
            # Nothing to cancel: responses are produced synchronously.
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("webView:stopURLSchemeTask:"),
            @@scheme_stop_imp.not_nil!.pointer.as(Void*), "v@:@@")

          handler = ObjC.send0(objc_class, ObjC.sel("new"))
          ObjC.bind_target(handler, self)
          handler
        end

        protected def handle_scheme_task(task : Void*) : Nil
          request = ObjC.send0(task, ObjC.sel("request"))
          url = ObjC.send0(request, ObjC.sel("URL"))
          path = ObjC.to_s(ObjC.send0(url, ObjC.sel("path"))) || "/"
          scheme = ObjC.to_s(ObjC.send0(url, ObjC.sel("scheme"))) || ""

          response = @scheme_handlers[scheme]?.try(&.call(path))
          if response
            finish_scheme_task(task, url, 200, response.mime_type, response.bytes)
          else
            # No handler / not found: empty body beats crashing the request.
            finish_scheme_task(task, url, 404, "text/plain; charset=utf-8", Bytes.empty)
          end
        end

        private def finish_scheme_task(task : Void*, url : Void*, status : Int64, mime_type : String, bytes : Bytes) : Nil
          # WKURLSchemeTask expects an NSHTTPURLResponse; the MIME type
          # travels as the Content-Type header field.
          headers = ObjC.send2(
            ObjC.cls("NSDictionary"), ObjC.sel("dictionaryWithObject:forKey:"),
            ObjC.nsstr(mime_type), ObjC.nsstr("Content-Type"))
          http = ObjC.send4(
            ObjC.send0(ObjC.cls("NSHTTPURLResponse"), ObjC.sel("alloc")),
            ObjC.sel("initWithURL:statusCode:HTTPVersion:headerFields:"),
            url, ObjC.int_arg(status), ObjC.nsstr("HTTP/1.1"), headers)
          ObjC.send1(task, ObjC.sel("didReceiveResponse:"), http)
          ObjC.send1(task, ObjC.sel("didReceiveData:"), ObjC.nsdata(bytes)) unless bytes.empty?
          ObjC.send0(task, ObjC.sel("didFinish"))
        end

        # NSWindow delegate: intercepts the close button (hide instead of
        # destroy when closing to tray) and reports window state changes
        # on the EventBus, mirroring the WebKitGTK configure-event wiring.
        private def build_window_delegate : Void*
          objc_class = ObjC.new_class("PositronWindowDelegate")

          @@should_close_imp = ->(objc_self : Void*, _cmd : Void*, sender : Void*) do
            adapter = ObjC.target_for(objc_self).as?(WKWebView)
            return false if adapter.nil?
            if adapter.try(&.close_to_tray?)
              ObjC.send1(sender, ObjC.sel("orderOut:"), Pointer(Void).null)
            else
              App.request_stop
            end
            # Never let AppKit destroy the window — the event loop owns it.
            false
          end
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("windowShouldClose:"),
            @@should_close_imp.not_nil!.pointer.as(Void*), "B@:@")

          @@did_resize_imp = ->(objc_self : Void*, _cmd : Void*, notification : Void*) {
            adapter = ObjC.target_for(objc_self).as?(WKWebView)
            adapter.try(&.emit_window_state_changes)
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("windowDidResize:"),
            @@did_resize_imp.not_nil!.pointer.as(Void*), "v@:@")

          @@did_move_imp = ->(objc_self : Void*, _cmd : Void*, notification : Void*) {
            adapter = ObjC.target_for(objc_self).as?(WKWebView)
            adapter.try(&.emit_window_state_changes)
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("windowDidMove:"),
            @@did_move_imp.not_nil!.pointer.as(Void*), "v@:@")

          @@did_zoom_imp = ->(objc_self : Void*, _cmd : Void*, notification : Void*) {
            adapter = ObjC.target_for(objc_self).as?(WKWebView)
            adapter.try(&.emit_window_state_changes)
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("windowDidZoom:"),
            @@did_zoom_imp.not_nil!.pointer.as(Void*), "v@:@")

          delegate = ObjC.send0(objc_class, ObjC.sel("new"))
          ObjC.bind_target(delegate, self)
          delegate
        end

        # Diff cached size/position/maximized state and broadcast changes
        # (same events as the WebKitGTK adapter's configure handler).
        protected def emit_window_state_changes
          width, height = size
          if @last_size != {width, height}
            @last_size = {width, height}
            Positron::EventBus.emit(
              "window.resized",
              JSON.parse(%({"width":#{width},"height":#{height}})))
          end

          x, y = position
          if @last_position != {x, y}
            @last_position = {x, y}
            Positron::EventBus.emit(
              "window.moved",
              JSON.parse(%({"x":#{x},"y":#{y}})))
          end

          maximized = maximized?
          if @last_maximized != maximized
            @last_maximized = maximized
            Positron::EventBus.emit(
              maximized ? "window.maximized" : "window.unmaximized",
              JSON.parse(%({})))
          end
        end
      end
    end
  end
end
