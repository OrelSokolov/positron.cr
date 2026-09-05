require "json"
require "log"
require "uri"

module CrystalUI
  module Adapters
    module Linux
      # Linux desktop WebView backed by WebKitGTK 4.1.
      #
      # Implements the platform-agnostic WebViewPort contract:
      #   - Creates a GTK window and WebKit view.
      #   - Loads URLs or raw HTML.
      #   - Injects a generic `CrystalBridge.postMessage` shim.
      #   - Forwards JS messages to the host and evaluates host responses.
      class WebKitGTK < WebViewPort
        @window : Void*
        @web_view : Void*
        @user_content_manager : Void*
        @callback : Proc(String, String)?
        @message_handler : Proc(Void*, Void*, Void*, Nil)?
        @delete_handler : Proc(Void*, Void*, Void*, Int32)?
        @configure_handler : Proc(Void*, Void*, Void*, Int32)?
        @drag_handler : Proc(Void*, Void*, Int32, Int32, Void*, UInt32, UInt32, Void*, Nil)?
        @close_to_tray : Bool = true
        @last_size : {Int32, Int32} = {-1, -1}
        @last_position : {Int32, Int32} = {-1, -1}
        @last_maximized : Bool = false
        @scheme_handlers : Hash(String, Proc(String, CrystalUI::SchemeResponse?))
        @scheme_callbacks : Array(Proc(Void*, Void*, Nil))
        @empty_byte : UInt8 = 0

        def initialize
          @window = Pointer(Void).null
          @web_view = Pointer(Void).null
          @user_content_manager = Pointer(Void).null
          @scheme_handlers = {} of String => Proc(String, CrystalUI::SchemeResponse?)
          @scheme_callbacks = [] of Proc(Void*, Void*, Nil)
        end

        def create(config : WebViewConfig)
          argc = 0
          LibGTK.gtk_init(pointerof(argc), nil)

          @window = LibGTK.gtk_window_new(0) # GTK_WINDOW_TOPLEVEL
          LibGTK.gtk_window_set_title(@window, config.title)
          LibGTK.gtk_window_set_default_size(@window, config.width, config.height)

          if icon = config.icon
            icon_path = write_temp_icon(icon)
            if icon_path && File.exists?(icon_path)
              LibGTK.gtk_window_set_icon_from_file(@window, icon_path, nil)
            end
          end

          # Intercept the window close button: hide instead of destroy so the
          # tray "Open" action can bring the window back — unless the app
          # opted out with WebViewConfig#close_to_tray=false (no tray).
          @close_to_tray = config.close_to_tray
          @delete_handler = ->(widget : Void*, event : Void*, data : Void*) do
            webkit = Box(WebKitGTK).unbox(data)
            if webkit.close_to_tray?
              webkit.hide
            else
              webkit.quit_event_loop
            end
            1 # TRUE: stop the default destroy behavior
          end

          LibGObject.g_signal_connect_data(
            @window,
            "delete-event",
            @delete_handler.not_nil!.pointer.as(Void*),
            Box.box(self),
            nil,
            0
          )

          connect_window_signals
          enable_file_drag_and_drop

          @web_view = LibWebKit.webkit_web_view_new
          @user_content_manager = LibWebKit.webkit_web_view_get_user_content_manager(@web_view)

          LibGTK.gtk_container_add(@window, @web_view)
        end

        def load_url(url : String)
          LibWebKit.webkit_web_view_load_uri(@web_view, url)
        end

        def load_html(html : String, base_url : String? = nil)
          base = base_url || ""
          LibWebKit.webkit_web_view_load_html(@web_view, html, base)
        end

        def eval_js(script : String)
          LibWebKit.webkit_web_view_run_javascript(@web_view, script, nil, nil, nil)
        end

        def show
          LibGTK.gtk_widget_show_all(@window)
        end

        def hide
          LibGTK.gtk_widget_hide(@window)
        end

        # Serve a custom URI scheme (`app://…`) straight from the host process
        # via WebKit's register_uri_scheme — embedded assets need no HTTP
        # server. Must be called before `create` (WebKit freezes the scheme
        # list when the WebView spawns its web process).
        def register_uri_scheme(scheme : String, &handler : String -> CrystalUI::SchemeResponse?)
          @scheme_handlers[scheme] = handler

          callback = ->(request : Void*, user_data : Void*) {
            webkit = Box(WebKitGTK).unbox(user_data)
            webkit.handle_scheme_request(request)
          }
          @scheme_callbacks << callback # keep the proc alive for C

          context = LibWebKit.webkit_web_context_get_default
          LibWebKit.webkit_web_context_register_uri_scheme(
            context,
            scheme,
            callback.pointer.as(Void*),
            Box.box(self),
            Pointer(Void).null
          )
        end

        protected def handle_scheme_request(request : Void*)
          uri = String.new(LibWebKit.webkit_uri_scheme_request_get_uri(request))
          scheme = uri.split(":", 2)[0]?
          path = String.new(LibWebKit.webkit_uri_scheme_request_get_path(request))

          response = scheme ? @scheme_handlers[scheme]?.try(&.call(path)) : nil
          if response
            bytes = response.bytes
            stream = LibGIO.g_memory_input_stream_new_from_data(
              bytes.to_unsafe, bytes.size.to_i64, Pointer(Void).null)
            LibWebKit.webkit_uri_scheme_request_finish(
              request, stream, bytes.size.to_i64, response.mime_type)
          else
            # No handler / not found: empty body beats crashing the request.
            stream = LibGIO.g_memory_input_stream_new_from_data(
              pointerof(@empty_byte), 0_i64, Pointer(Void).null)
            LibWebKit.webkit_uri_scheme_request_finish(
              request, stream, 0_i64, "text/plain; charset=utf-8")
          end
        end

        protected def close_to_tray? : Bool
          @close_to_tray
        end

        protected def quit_event_loop
          LibGTK.gtk_main_quit
        end

        def bind(name : String, &block : String -> String)
          @callback = block

          unless LibWebKit.webkit_user_content_manager_register_script_message_handler(
                   @user_content_manager, name) == 1
            raise "Failed to register JS message handler '#{name}'"
          end

          inject_bridge_shim(name)

          data_ptr = Box.box(self)

          @message_handler = ->(manager : Void*, js_result : Void*, data : Void*) do
            webkit = Box(WebKitGTK).unbox(data)
            jsc_value = LibWebKit.webkit_javascript_result_get_js_value(js_result)
            json = LibJSC.jsc_value_to_json(jsc_value, 0)
            message = String.new(json)
            LibGLib.g_free(json)
            if cb = webkit.callback
              response = cb.call(message)
              webkit.eval_js(response) unless response.empty?
            end
          end

          LibGObject.g_signal_connect_data(
            @user_content_manager,
            "script-message-received::#{name}",
            @message_handler.not_nil!.pointer.as(Void*),
            data_ptr,
            nil,
            0
          )
        end

        protected def callback : Proc(String, String)?
          @callback
        end

        def run_event_loop
          LibGTK.gtk_main
        end

        def close
          LibGTK.gtk_main_quit
        end

        # --- Window management (WebViewPort) ---

        def set_title(title : String) : Nil
          LibGTK.gtk_window_set_title(@window, title)
        end

        def resize(width : Int32, height : Int32) : Nil
          LibGTK.gtk_window_resize(@window, width, height)
        end

        def center : Nil
          LibGTK.gtk_window_set_position(@window, LibGTK::GTK_WIN_POS_CENTER)
        end

        def set_minimum_size(width : Int32, height : Int32) : Nil
          apply_geometry_hints(min: {width, height})
        end

        def set_maximum_size(width : Int32, height : Int32) : Nil
          apply_geometry_hints(max: {width, height})
        end

        def maximize : Nil
          LibGTK.gtk_window_maximize(@window)
        end

        def unmaximize : Nil
          LibGTK.gtk_window_unmaximize(@window)
        end

        def maximized? : Bool
          LibGTK.gtk_window_is_maximized(@window) == 1
        end

        def fullscreen : Nil
          LibGTK.gtk_window_fullscreen(@window)
          CrystalUI::EventBus.emit("window.fullscreened", JSON.parse(%({})))
        end

        def unfullscreen : Nil
          LibGTK.gtk_window_unfullscreen(@window)
          CrystalUI::EventBus.emit("window.unfullscreened", JSON.parse(%({})))
        end

        def set_always_on_top(enabled : Bool) : Nil
          LibGTK.gtk_window_set_keep_above(@window, enabled ? 1 : 0)
        end

        def set_decorated(decorated : Bool) : Nil
          LibGTK.gtk_window_set_decorated(@window, decorated ? 1 : 0)
        end

        def focus : Nil
          LibGTK.gtk_window_present(@window)
        end

        def size : {Int32, Int32}
          width = 0
          height = 0
          LibGTK.gtk_window_get_size(@window, pointerof(width), pointerof(height))
          {width, height}
        end

        def position : {Int32, Int32}
          x = 0
          y = 0
          LibGTK.gtk_window_get_position(@window, pointerof(x), pointerof(y))
          {x, y}
        end

        # --- Developer tools (WebKitGTK Web Inspector) ---

        def open_devtools : Nil
          LibWebKit.webkit_web_inspector_show(inspector)
        end

        def close_devtools : Nil
          LibWebKit.webkit_web_inspector_close(inspector)
        end

        def devtools_open? : Bool
          !LibWebKit.webkit_web_inspector_get_web_view(inspector).null?
        end

        private def inspector : Void*
          LibWebKit.webkit_web_view_get_inspector(@web_view)
        end

        # Set min/max size constraints via GdkGeometry hints. Only the
        # requested hint is applied; the other bound stays unlimited.
        private def apply_geometry_hints(min : {Int32, Int32}? = nil, max : {Int32, Int32}? = nil)
          # GdkGeometry starts with min_width, min_height, max_width, max_height.
          geometry = Pointer(Int32).malloc(16)
          4.times { |i| geometry[i] = 0 }

          mask = 0_u32
          if min
            geometry[0], geometry[1] = min[0], min[1]
            mask |= LibGTK::GDK_HINT_MIN_SIZE
          end
          if max
            geometry[2], geometry[3] = max[0], max[1]
            mask |= LibGTK::GDK_HINT_MAX_SIZE
          end

          LibGTK.gtk_window_set_geometry_hints(
            @window, Pointer(Void).null, geometry.as(Void*), mask)
        end

        # Wire the GTK "configure-event" signal; on each event, diff the
        # cached size/position/maximized state and broadcast changes.
        private def connect_window_signals
          @last_size = {-1, -1}
          @last_position = {-1, -1}

          @configure_handler = ->(widget : Void*, event : Void*, data : Void*) do
            webkit = Box(WebKitGTK).unbox(data)
            webkit.emit_window_state_changes
            0 # FALSE: let GTK process the event normally
          end

          LibGObject.g_signal_connect_data(
            @window,
            "configure-event",
            @configure_handler.not_nil!.pointer.as(Void*),
            Box.box(self),
            nil,
            0
          )
        end

        protected def emit_window_state_changes
          width, height = size
          if @last_size != {width, height}
            @last_size = {width, height}
            CrystalUI::EventBus.emit(
              "window.resized",
              JSON.parse(%({"width":#{width},"height":#{height}}))
            )
          end

          x, y = position
          if @last_position != {x, y}
            @last_position = {x, y}
            CrystalUI::EventBus.emit(
              "window.moved",
              JSON.parse(%({"x":#{x},"y":#{y}}))
            )
          end

          maximized = maximized?
          if @last_maximized != maximized
            @last_maximized = maximized
            CrystalUI::EventBus.emit(
              maximized ? "window.maximized" : "window.unmaximized",
              JSON.parse(%({}))
            )
          end
        end

        # Accept file drops on the window. Dropped files are decoded from
        # `file://` URIs and broadcast as `dnd.files` on the EventBus
        # (the host forwards them to the frontend).
        GTK_DEST_DEFAULT_ALL = 7
        GDK_ACTION_COPY      = 1

        private def enable_file_drag_and_drop
          LibGTK.gtk_drag_dest_set(
            @window, GTK_DEST_DEFAULT_ALL,
            Pointer(Void).null, 0, GDK_ACTION_COPY)
          LibGTK.gtk_drag_dest_add_uri_targets(@window)

          @drag_handler = ->(widget : Void*, context : Void*, x : Int32, y : Int32,
                             data : Void*, info : UInt32, time : UInt32, user_data : Void*) do
            webkit = Box(WebKitGTK).unbox(user_data)
            uris_ptr = LibGTK.gtk_selection_data_get_uris(data)

            paths = [] of String
            unless uris_ptr.null?
              cursor = uris_ptr
              while (str_ptr = cursor.value).null? == false
                uri = String.new(str_ptr)
                paths << decode_file_uri(uri) if uri.starts_with?("file://")
                cursor += 1
              end
              LibGLib.g_strfreev(uris_ptr)
            end

            unless paths.empty?
              CrystalUI::EventBus.emit(
                "dnd.files",
                JSON.parse({files: paths}.to_json)
              )
            end
            nil
          end

          LibGObject.g_signal_connect_data(
            @window,
            "drag-data-received",
            @drag_handler.not_nil!.pointer.as(Void*),
            Box.box(self),
            nil,
            0
          )
        end

        # file:///path/with%20spaces → /path/with spaces
        private def decode_file_uri(uri : String) : String
          URI.decode(uri.lchop("file://"))
        end

        private def inject_bridge_shim(handler_name : String)          shim = <<-JS
            window.CrystalBridge = window.CrystalBridge || {
              postMessage: function(jsonString) {
                window.webkit.messageHandlers.#{handler_name}.postMessage(JSON.parse(jsonString));
              }
            };
          JS

          # Inject the shim as a user script so it is available on every page,
          # including pages loaded after bind() is called.
          script = LibWebKit.webkit_user_script_new(
            shim,
            LibWebKit::WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
            LibWebKit::WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
            nil,
            nil
          )
          LibWebKit.webkit_user_content_manager_add_script(@user_content_manager, script)
        end

        private def write_temp_icon(icon : IconSource) : String?
          ext = case icon.format
                when :svg then "svg"
                when :png then "png"
                when :ico then "ico"
                else           "bin"
                end
          tmpdir = Dir.tempdir
          path = File.join(tmpdir, "crystalui_icon_#{Process.pid}_#{Time.utc.to_unix_ms}.#{ext}")
          File.write(path, icon.bytes)
          path
        rescue ex
          Log.warn { "Failed to write temp icon: #{ex.message}" }
          nil
        end

        @[Link("gtk-3")]
        lib LibGTK
          GTK_WIN_POS_CENTER = 2

          GDK_HINT_MIN_SIZE = 1 << 1
          GDK_HINT_MAX_SIZE = 1 << 3

          fun gtk_init(argc : Int32*, argv : Void**)
          fun gtk_window_new(type : Int32) : Void*
          fun gtk_window_set_title(window : Void*, title : LibC::Char*)
          fun gtk_window_set_default_size(window : Void*, width : Int32, height : Int32)
          fun gtk_window_resize(window : Void*, width : Int32, height : Int32)
          fun gtk_window_get_size(window : Void*, width : Int32*, height : Int32*)
          fun gtk_window_get_position(window : Void*, x : Int32*, y : Int32*)
          fun gtk_window_set_position(window : Void*, position : Int32)
          fun gtk_window_set_geometry_hints(window : Void*, geometry_widget : Void*, geometry : Void*, geom_mask : UInt32)
          fun gtk_window_set_icon_from_file(window : Void*, filename : LibC::Char*, err : Void**) : Int32
          fun gtk_window_maximize(window : Void*)
          fun gtk_window_unmaximize(window : Void*)
          fun gtk_window_is_maximized(window : Void*) : Int32
          fun gtk_window_fullscreen(window : Void*)
          fun gtk_window_unfullscreen(window : Void*)
          fun gtk_window_set_keep_above(window : Void*, setting : Int32)
          fun gtk_window_set_decorated(window : Void*, setting : Int32)
          fun gtk_window_present(window : Void*)
          fun gtk_container_add(container : Void*, widget : Void*)
          fun gtk_drag_dest_set(widget : Void*, flags : Int32, targets : Void*, n_targets : Int32, actions : UInt32)
          fun gtk_drag_dest_add_uri_targets(widget : Void*)
          fun gtk_selection_data_get_uris(selection_data : Void*) : LibC::Char**
          fun gtk_widget_show_all(widget : Void*)
          fun gtk_widget_hide(widget : Void*)
          fun gtk_main
          fun gtk_main_quit
        end

        @[Link("gobject-2.0")]
        lib LibGObject
          fun g_signal_connect_data(
            instance : Void*,
            detailed_signal : LibC::Char*,
            c_handler : Void*,
            data : Void*,
            destroy_data : Void*,
            connect_flags : Int32,
          ) : UInt64
        end

        @[Link("webkit2gtk-4.1")]
        lib LibWebKit
          WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES = 0
          WEBKIT_USER_CONTENT_INJECT_TOP_FRAME  = 1

          WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START = 0
          WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END   = 1

          fun webkit_web_view_new : Void*
          fun webkit_web_view_load_uri(web_view : Void*, uri : LibC::Char*)
          fun webkit_web_view_load_html(web_view : Void*, html : LibC::Char*, base_uri : LibC::Char*)
          fun webkit_web_view_run_javascript(web_view : Void*, script : LibC::Char*, cancellable : Void*, callback : Void*, user_data : Void*)
          fun webkit_web_view_get_user_content_manager(web_view : Void*) : Void*
          fun webkit_web_view_get_inspector(web_view : Void*) : Void*
          fun webkit_user_content_manager_register_script_message_handler(manager : Void*, name : LibC::Char*) : Int32
          fun webkit_user_content_manager_add_script(manager : Void*, script : Void*)
          fun webkit_user_script_new(source : LibC::Char*, injected_frames : UInt32, injection_time : UInt32, allow_list : Void*, block_list : Void*) : Void*
          fun webkit_javascript_result_get_js_value(js_result : Void*) : Void*
          fun webkit_web_inspector_show(inspector : Void*)
          fun webkit_web_inspector_close(inspector : Void*)
          fun webkit_web_inspector_get_web_view(inspector : Void*) : Void*
          fun webkit_web_context_get_default : Void*
          fun webkit_web_context_register_uri_scheme(context : Void*, scheme : LibC::Char*, callback : Void*, user_data : Void*, destroy_notify : Void*)
          fun webkit_uri_scheme_request_get_uri(request : Void*) : LibC::Char*
          fun webkit_uri_scheme_request_get_path(request : Void*) : LibC::Char*
          fun webkit_uri_scheme_request_finish(request : Void*, stream : Void*, stream_length : Int64, content_type : LibC::Char*)
        end

        @[Link("gio-2.0")]
        lib LibGIO
          fun g_memory_input_stream_new_from_data(data : UInt8*, length : Int64, destroy : Void*) : Void*
        end

        @[Link("javascriptcoregtk-4.1")]
        lib LibJSC
          fun jsc_value_to_json(value : Void*, indent : UInt32) : LibC::Char*
        end

        @[Link("glib-2.0")]
        lib LibGLib
          fun g_free(mem : Void*)
          fun g_strfreev(str_array : LibC::Char**)
        end
      end
    end
  end
end
