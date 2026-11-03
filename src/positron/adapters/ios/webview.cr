require "json"
require "log"
require "./objc"

module Positron
  module Adapters
    module IOS
      # iOS WebView backed by WKWebView inside a UIWindow.
      #
      # Implements the platform-agnostic WebViewPort contract on top of
      # the same WebKit machinery as the macOS adapter (WKUserScript
      # bridge shim, a dynamically registered WKScriptMessageHandler,
      # WKURLSchemeHandler for custom URI schemes — embedded assets
      # need no HTTP server; handlers must be registered before
      # `create`).
      #
      # Threading/boot order differs from macOS: the application calls
      # `create` (from `on_ready`) *before* the event loop enters
      # `UIApplicationMain`, but UIKit UI objects may only be built
      # once the application object exists. So `create` only prepares
      # the WKWebViewConfiguration; the UIWindow / view controller /
      # WKWebView are built by `#boot`, which the AppDelegate IMP
      # (`event_loop/ios.cr`) calls from
      # `application:didFinishLaunchingWithOptions:`. Loads and
      # evaluations issued before boot are queued and replayed in
      # order afterwards.
      #
      # Window management is intentionally left at the WebViewPort
      # defaults (raise): on iOS the "window" is the scene managed by
      # UIKit, the same way the Android adapter treats the Activity.
      class WKWebView < WebViewPort
        @window : Void*?
        @wk_view : Void*?
        @wk_config : Void*?
        @user_controller : Void*?
        @message_handler_obj : Void*?
        @scheme_handler_obj : Void*?
        @callback : Proc(String, String)?
        @scheme_handlers = {} of String => Proc(String, Positron::SchemeResponse?)
        @pending = [] of Proc(Nil)
        @ui_delegate_obj : Void*?

        # IMP proc objects — kept alive so the C function pointers stay
        # valid for the lifetime of the process.
        @@message_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
        @@media_permission_imp : Proc(Void*, Void*, Void*, Void*, Void*, Void*, Void*, Nil)?
        @@scheme_start_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
        @@scheme_stop_imp : Proc(Void*, Void*, Void*, Void*, Nil)?

        # Flexible width (2) | flexible height (16): the webview tracks
        # the root view through rotations and scene resizes.
        AUTORESIZING_MASK = 2_i64 | 16_i64

        def initialize
        end

        # Pre-boot half: builds the WKWebViewConfiguration (custom
        # scheme handlers must attach here, before the WKWebView is
        # instantiated in #boot).
        def create(config : WebViewConfig)
          ObjC.with_autorelease_pool do
            wk_config = ObjC.send0(ObjC.cls("WKWebViewConfiguration"), ObjC.sel("new"))
            @wk_config = wk_config
            @user_controller = ObjC.send0(wk_config, ObjC.sel("userContentController"))

            unless @scheme_handlers.empty?
              @scheme_handler_obj = build_scheme_handler
              @scheme_handlers.each_key do |scheme|
                ObjC.send2(
                  wk_config,
                  ObjC.sel("setURLSchemeHandler:forURLScheme:"),
                  @scheme_handler_obj.not_nil!, ObjC.nsstr(scheme))
              end
            end

            # Right-click "Inspect Element" via Safari on the simulator;
            # harmless when unavailable.
            prefs = ObjC.send0(wk_config, ObjC.sel("preferences"))
            ObjC.send2(
              prefs, ObjC.sel("setValue:forKey:"),
              ObjC.nsbool(true), ObjC.nsstr("developerExtrasEnabled"))
          end
        end

        # Boot half — called by the AppDelegate IMP once UIApplication
        # exists. Idempotent.
        def boot : Nil
          return if @window
          ObjC.with_autorelease_pool do
            bounds = ObjC::Call.new(
              ObjC.send0(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")),
              "bounds").invoke.ret_rect

            window = ObjC.send0(ObjC.cls("UIWindow"), ObjC.sel("alloc"))
            ObjC.invoke_rect3(window, "initWithFrame:", bounds)

            wk_view = ObjC.send0(ObjC.cls("WKWebView"), ObjC.sel("alloc"))
            ObjC.invoke_rect3(
              wk_view, "initWithFrame:configuration:", bounds, @wk_config.not_nil!)

            # Bare UIViewController whose view IS the webview — the
            # webview then fills the window and follows scene resizes.
            vc = ObjC.send0(ObjC.cls("UIViewController"), ObjC.sel("new"))
            ObjC.send1(vc, ObjC.sel("setView:"), wk_view)
            ObjC.send1(window, ObjC.sel("setRootViewController:"), vc)
            ObjC.send0(window, ObjC.sel("makeKeyAndVisible"))
            ObjC.send1(wk_view, ObjC.sel("setAutoresizingMask:"), ObjC.int_arg(AUTORESIZING_MASK))

            @wk_view = wk_view
            @window = window

            # WKUIDelegate granting media-capture (getUserMedia) — iOS
            # twin of the macOS/Linux/Windows permission handlers.
            # Without the delegate WKWebView denies getUserMedia
            # outright; with the grant the OS-level TCC prompt still
            # applies on a real device (needs NSCameraUsageDescription /
            # NSMicrophoneUsageDescription in the bundle — see
            # ios/Info.plist).
            @ui_delegate_obj = build_ui_delegate
            ObjC.send1(wk_view, ObjC.sel("setUIDelegate:"), @ui_delegate_obj.not_nil!)

            pending = @pending
            @pending = [] of Proc(Nil)
            pending.each(&.call)
          end
        end

        def booted? : Bool
          !@wk_view.nil?
        end

        # Presents a UIKit view controller modally over the app window
        # (used by plugin adapters, e.g. UIDocumentPickerViewController).
        # Returns false when there is no booted window / root view
        # controller to present from.
        def present_modal(view_controller : Void*) : Bool
          return false unless window = @window
          root = ObjC.send0(window, ObjC.sel("rootViewController"))
          return false if root.null?
          # NULL completion handler is explicitly allowed.
          ObjC.send3(root, ObjC.sel("presentViewController:animated:completion:"),
            view_controller, ObjC.bool_arg(true), Pointer(Void).null)
          true
        end

        def load_url(url : String)
          after_boot do
            request = ObjC.send1(
              ObjC.send0(ObjC.cls("NSURLRequest"), ObjC.sel("alloc")),
              ObjC.sel("initWithURL:"), ObjC.nsurl(url))
            ObjC.send1(wk_view, ObjC.sel("loadRequest:"), request)
          end
        end

        def load_html(html : String, base_url : String? = nil)
          after_boot do
            base = base_url ? ObjC.nsurl(base_url) : Pointer(Void).null
            ObjC.send2(wk_view, ObjC.sel("loadHTMLString:baseURL:"), ObjC.nsstr(html), base)
          end
        end

        def eval_js(script : String)
          after_boot do
            # A NULL completion handler is explicitly allowed.
            ObjC.send2(
              wk_view, ObjC.sel("evaluateJavaScript:completionHandler:"),
              ObjC.nsstr(script), Pointer(Void).null)
          end
        end

        def show
          # The window is made key and visible in #boot; UIKit owns
          # the scene from there on.
        end

        def hide
        end

        def close
          # iOS apps do not close their window; Host#stop exits the
          # process (see EventLoop::IOS#stop).
          Log.info { "ios: webview close requested (no-op on iOS)" }
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

        def open_devtools : Nil
          Log.warn { "ios: WKWebView devtools need Safari on the simulator (developerExtrasEnabled is on)" }
        end

        def close_devtools : Nil
        end

        # --- Internals ---

        protected def callback : Proc(String, String)?
          @callback
        end

        private def wk_view : Void*
          @wk_view.not_nil!
        end

        # Run `block` now when booted, otherwise queue it for #boot.
        private def after_boot(&block : -> Nil) : Nil
          if booted?
            block.call
          else
            @pending << block
          end
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

        # Builds a WKUIDelegate granting media-capture (getUserMedia)
        # requests — same IMP pattern as the macOS adapter; every grant
        # is broadcast as `permission.requested`.
        private def build_ui_delegate : Void*
          objc_class = ObjC.new_class("PositronWKUIDelegate")
          ObjC.add_protocol(objc_class, "WKUIDelegate")

          @@media_permission_imp = ->(objc_self : Void*, _cmd : Void*, web_view : Void*, origin : Void*, frame : Void*, capture_type : Void*, decision : Void*) {
            # WKMediaCaptureType: 0 = camera, 1 = microphone,
            # 2 = camera + microphone.
            kind = case capture_type.address
                   when 0 then "camera"
                   when 1 then "microphone"
                   when 2 then "camera+microphone"
                   else        "media"
                   end
            # WKPermissionDecisionGrant (= 1); the argument is an
            # NSInteger enum, passed pointer-sized through call_block1.
            ObjC.call_block1(decision, ObjC.int_arg(1))
            Log.info { "wkwebview: granted #{kind} capture permission" }
            Positron::EventBus.emit(
              "permission.requested",
              JSON.parse({type: kind, granted: true}.to_json)
            )
          }
          Adapters::IOS::LibObjC.class_addMethod(
            objc_class,
            ObjC.sel("webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:"),
            @@media_permission_imp.not_nil!.pointer.as(Void*),
            "v@:@@@q@?")

          delegate = ObjC.send0(objc_class, ObjC.sel("new"))
          ObjC.bind_target(delegate, self)
          delegate
        end

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
            @@message_imp.not_nil!.pointer.as(Void*), "v@:@")

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
            @@scheme_start_imp.not_nil!.pointer.as(Void*), "v@:@")

          @@scheme_stop_imp = ->(objc_self : Void*, _cmd : Void*, web_view : Void*, task : Void*) {
            # Nothing to cancel: responses are produced synchronously.
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel("webView:stopURLSchemeTask:"),
            @@scheme_stop_imp.not_nil!.pointer.as(Void*), "v@:@")

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
      end
    end
  end
end
