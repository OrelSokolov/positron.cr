require "log"
require "../mobile/queue"

module Positron
  module EventLoop
    # Android event loop: the OS owns the main (Looper) thread, so the
    # Crystal runtime lives on a dedicated native host thread created by
    # the C shim (`android/positron_shim.c`). This adapter is the pump
    # that runs on that thread's GUI fiber.
    #
    # Every tick it drains the run_on_main queue
    # (`Positron::Mobile::MessageQueue`), gives the Crystal fiber
    # scheduler a chance to run pending fibers and timers, then sleeps
    # one frame. The sleep integrates with the scheduler, so sleeping
    # fibers (command handlers, debounce timers) wake on time; a tick
    # of latency for newly queued work is imperceptible.
    #
    # Events arriving from Java threads (JS bridge messages, lifecycle
    # callbacks, asset requests) do NOT enter through here — they come
    # through the C shim's copied-string queue and are drained by the
    # host's tick source registered with #on_tick.
    class Android < EventLoopPort
      Log = ::Log.for("positron.event_loop.android")

      # One frame: the upper bound for queued-work latency.
      TICK = 0.016_f64

      getter queue = Mobile::MessageQueue.new

      @tick_sources = [] of ->
      @running = false
      @gui_fiber : Fiber?

      def initialize
        # The GUI fiber is the host thread's main fiber — capture it
        # HERE, not only in #run: Application#on_ready runs before the
        # pump starts and its bridge calls (load_url!) must take the
        # direct path instead of marshalling into a queue that nothing
        # drains yet.
        @gui_fiber = Fiber.current
      end

      # Register a block drained on every pump tick (the Android host
      # pops C-shim events there). Runs on the GUI fiber.
      def on_tick(&block : ->) : Nil
        @tick_sources << block
      end

      def run : Nil
        @running = true
        @gui_fiber = Fiber.current
        Log.info { "pump started on host thread" }

        while @running
          @queue.drain
          @tick_sources.each(&.call)
          # Let runnable fibers (async_work handlers, timers) execute.
          Fiber.yield
          # Park the scheduler until the next tick: sleeping fibers
          # still wake on their own deadlines.
          sleep TICK.seconds
        end

        Log.info { "pump stopped" }
      end

      def stop : Nil
        @running = false
      end

      def running? : Bool
        @running
      end

      # Schedule a block on the GUI fiber (the pump's fiber on the
      # host thread). Safe to call from any Crystal fiber.
      def run_on_main(&block : ->) : Nil
        @queue.push(&block)
      end

      def gui_thread? : Bool
        # Before #run starts the pump, @gui_fiber is nil — but the
        # caller is the host thread's root fiber, the very fiber #run
        # will mark as the GUI fiber (Host#run calls on_ready, which
        # issues JNI calls, before the pump starts). Treating boot
        # code as the GUI context keeps those calls inline instead of
        # marshalling them into a queue nothing drains yet.
        gui = @gui_fiber
        gui.nil? || Fiber.current == gui
      end
    end
  end
end
