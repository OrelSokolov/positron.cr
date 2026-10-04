module Positron
  # Platform-agnostic event loop integration.
  #
  # On desktop the implementation combines the native GUI message loop with
  # the Crystal fiber scheduler. On mobile the OS already owns the main loop,
  # so the adapter mostly provides `run_on_main` to marshal work to the UI
  # thread.
  abstract class EventLoopPort
    abstract def run
    abstract def stop
    abstract def running? : Bool

    # Schedule a block to run on the main/GUI thread.
    abstract def run_on_main(&block : ->) : Nil
  end
end
