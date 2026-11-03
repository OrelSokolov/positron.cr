module Positron
  # Desktop host: single process, Crystal owns everything.
  #
  # Wires together the WebView, tray, command registry, plugins, EventBus,
  # state manager, and the platform event loop.
  class DesktopHost < Host
    getter webview : WebViewPort
    getter tray : TrayPort
    getter event_loop : EventLoopPort

    def initialize(app : Application)
      @webview = WebViewAdapter.new
      @tray = TrayAdapter.new
      @event_loop = PlatformEventLoop.new(@webview)

      # User-initiated window close goes through the application's
      # on_before_close hook (close veto). Host#stop stays unconditional.
      @webview.before_close = -> { app.on_before_close }

      super(app)

      @tray.create
    end

    def eval_js(script : String)
      @webview.eval_js(script)
    end

    def run_on_main(&block : ->) : Nil
      @event_loop.run_on_main(&block)
    end

    def gui_context? : Bool
      @event_loop.gui_thread?
    end

    def run
      @app.on_ready
      @plugins.each(&.on_ready(self))
      @event_loop.run
    end

    def stop
      @event_loop.stop
      @tray.quit
      @webview.close
    end
  end
end
