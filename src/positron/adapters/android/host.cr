require "log"
require "./async_bridge"
require "./jni"
require "./shim"
require "./webview"
require "../../event_loop/android"
require "../../mobile/asset_router"

module Positron
  module Adapters
    module Android
      # Android mobile host: Crystal owns all state and logic (same as
      # desktop); the Java Activity + PositronBridge are a passive
      # shim. Everything runs on the host thread created by the C shim
      # (see `android/positron_shim.c`): this host, the event loop
      # pump and every Crystal fiber.
      class Host < MobileHost
        Log = ::Log.for("positron.android.host")

        getter event_loop : EventLoop::Android
        getter asset_router : Mobile::AssetRouter
        getter bridge : LibJNI::JObject
        @webview : WebView?

        def initialize(app : Application)
          super(app, LibShim.positron_shim_webview, LibShim.positron_shim_activity)

          # From here on we are on the host thread: bind the JVM and
          # cache the bridge the Java side registered with the shim.
          JNI.vm = LibShim.positron_shim_vm
          @bridge = LibShim.positron_shim_bridge
          @event_loop = EventLoop::Android.new
          @asset_router = Mobile::AssetRouter.new
          @webview = WebView.new(self)
          @event_loop.on_tick { drain_shim_events }
        end

        # The WebView port exists from the end of #initialize on; the
        # nilable ivar only accommodates the inherited MobileHost
        # constructor during partial construction.
        def webview : WebView
          @webview.not_nil!
        end

        def eval_js(script : String)
          webview.eval_js(script)
        end

        def run_on_main(&block : ->) : Nil
          @event_loop.run_on_main(&block)
        end

        def gui_context? : Bool
          @event_loop.gui_thread?
        end

        def run
          Log.info { "android host starting" }
          @app.on_ready
          @plugins.each(&.on_ready(self))
          @event_loop.run
        end

        def stop
          @event_loop.stop
        end

        # --- shim routing (all on the GUI fiber) ---

        private def drain_shim_events : Nil
          kind = Pointer(Int32).malloc(1)
          a = Pointer(Pointer(UInt8)).malloc(1)
          b = Pointer(Pointer(UInt8)).malloc(1)

          while LibShim.positron_shim_pop(kind, a, b) != 0
            begin
              case kind.value
              when LibShim::EVT_MESSAGE then webview.handle_message(String.new(a.value))
              when LibShim::EVT_EVENT   then handle_event(read_name(a.value), read_payload(b.value))
              when LibShim::EVT_STOP    then handle_stop
              end
            rescue ex
              # A bad message must never kill the pump.
              Log.error(exception: ex) { "error handling shim event ##{kind.value}" }
            ensure
              LibShim.positron_shim_free(a.value) if a.value
              LibShim.positron_shim_free(b.value) if b.value
            end
          end

          serve_pending_asset
        end

        private def read_name(ptr : UInt8*) : String
          ptr ? String.new(ptr) : ""
        end

        private def read_payload(ptr : UInt8*) : String
          ptr ? String.new(ptr) : "{}"
        end

        # OS events forwarded by the Activity: lifecycle, deep_link,
        # permission_result. Lifecycle transitions ride the same
        # window.focused/blurred events as on desktop — the base Host
        # already maps those to Application#on_lifecycle and the
        # lifecycle plugin mirrors them to the frontend.
        private def handle_event(name : String, payload : String) : Nil
          case name
          when "lifecycle"
            state = begin
              JSON.parse(payload)["state"]?.try(&.as_s?) || ""
            rescue JSON::ParseException
              ""
            end
            case state
            when "resume" then EventBus.emit("window.focused", JSON.parse("{}"))
            when "pause"  then EventBus.emit("window.blurred", JSON.parse("{}"))
            when "destroy"
              EventBus.emit("app.quitting", JSON.parse("{}"))
              @app.on_lifecycle("destroy")
            end
          when "deep_link"
            url = begin
              JSON.parse(payload)["url"]?.try(&.as_s?) || ""
            rescue JSON::ParseException
              ""
            end
            @app.on_deep_link(url) unless url.empty?
          when "permission_result"
            parsed = begin
              JSON.parse(payload)
            rescue JSON::ParseException
              nil
            end
            if parsed
              permission = parsed["permission"]?.try(&.as_s?) || ""
              granted = parsed["granted"]?.try(&.as?(Bool)) == true
              @app.on_permission_result(permission, granted) unless permission.empty?
              EventBus.emit("permission.result", parsed)
            end
          when "saf_result", "dialog_result"
            # Async native roundtrips (SAF pickers, native dialogs):
            # hand the raw payload to the registered continuation.
            seq = begin
              JSON.parse(payload)["seq"]?.try(&.as_i?)
            rescue JSON::ParseException
              nil
            end
            AsyncBridge.complete(seq, payload) if seq
          when "notification_click"
            parsed = begin
              JSON.parse(payload)
            rescue JSON::ParseException
              nil
            end
            EventBus.emit("android.notification_click", parsed) if parsed
          else
            Log.warn { "unknown shim event: #{name}" }
          end
        end

        private def handle_stop : Nil
          Log.info { "activity destroyed — stopping host" }
          @event_loop.stop
        end

        # Answer one pending shouldInterceptRequest roundtrip. No
        # registered scheme handler → empty 404 (the WebView shows its
        # own error page).
        private def serve_pending_asset : Nil
          req = LibShim.positron_shim_asset_take
          return unless req

          path = String.new(LibShim.positron_shim_asset_path(req))
          response = @asset_router.serve_path(path)
          if response
            LibShim.positron_shim_asset_done(req, response.bytes.to_unsafe, response.bytes.size, response.mime_type.to_unsafe)
          else
            LibShim.positron_shim_asset_done(req, nil, 0, nil)
          end
        rescue ex
          Log.error(exception: ex) { "asset request failed: #{ex.message}" }
          LibShim.positron_shim_asset_done(req, nil, 0, nil) if req
        end
      end
    end
  end
end
